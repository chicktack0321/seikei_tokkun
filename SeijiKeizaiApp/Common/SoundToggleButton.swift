import SwiftUI

/// 音のオン・オフを切り替えるツールバーボタン。
///
/// 設定の保存先は `GameAudio` が持っているため、この画面側では状態を持たない。
struct SoundToggleButton: View {
    /// 進行中の画面かどうか。音を戻したときにBGMを鳴らし直すかの判断に使う。
    var isSessionActive: Bool

    // 実体は常に同じインスタンス。@Observable なので isEnabled の変化で再描画される。
    @State private var audio = GameAudio.shared

    var body: some View {
        Button {
            audio.isEnabled.toggle()
            if audio.isEnabled, isSessionActive {
                audio.startBGM()
            }
        } label: {
            Image(systemName: audio.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
        }
        .accessibilityLabel(audio.isEnabled ? "音を消す" : "音を出す")
    }
}
