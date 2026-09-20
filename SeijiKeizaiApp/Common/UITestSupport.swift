import Foundation

/// UIテストからだけ有効になる補助。
///
/// 起動引数が無ければ既定値のままなので、通常の実行には影響しない。
enum UITestSupport {
    /// 正解の選択肢に、他と違うアクセシビリティ識別子を付けるか。
    ///
    /// 出題は収録データと習熟度によって変わるため、UIテストからは「どれが正解か」を知る手段がない。
    /// 適当な選択肢を押すと結果が実行ごとに変わり、App Store用に撮る「正解したときの解説画面」を
    /// 安定して用意できないので、この起動引数を渡したときだけ正解を識別できるようにする。
    static let revealsCorrectChoice = ProcessInfo.processInfo.arguments.contains(Self.revealCorrectChoiceArgument)

    /// UIテスト側と綴りを合わせるための定数
    static let revealCorrectChoiceArgument = "-uiTestRevealsCorrectChoice"
}
